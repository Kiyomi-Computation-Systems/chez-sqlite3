#!/usr/bin/env python3
"""Plant each mutant in a copy of the worktree, under build/t/mut/NAME/.
Each mutant is a list of edits (file, old, new); each old must match its
file exactly once. Writes build/t/mut/NAME/SUITES, the suites to run."""
import os, subprocess, sys, json
root = os.getcwd()  # run from the worktree's root, as build/t/mutants.py was
T = 'src/chez-sqlite3/private/transaction.sls'
I = 'src/chez-sqlite3/private/interrupt.sls'
C = 'src/chez-sqlite3/private/connection.sls'
TX = ['tests/test-transaction.sps', 'tests/test-transaction-engine.sps', 'tests/test-interrupt-database.sps']
ALL = TX + ['tests/test-interrupt.sps', 'tests/test-public.sps']
SHUT = ['tests/test-interrupt.sps', 'tests/test-interrupt-database.sps']

begun_head = """        (let ((outcome
               (critical-section
                (if (not (claim!))
                    '(claimed)
                    (let ((plan (guard (c (#t (list 'raised c)))
                                  (call-with-open-handle who db
                                    (lambda (handle)
                                      (let ((held (held-state db)))
                                        (if held
                                            (cons 'not-finished held)
                                            (begin-plan (sqlite3-get-autocommit handle) (database-depth db)
                                                        mode))))))))
                      (if (eq? (car plan) 'begin)"""

mutants = {
 # --- the claim
 'M01-no-claim': ([(T, "(claim! (lambda () (and (not taken) (begin (set! taken #t) #t)))))",
                      "(claim! (lambda () #t)))")], TX),
 'M02-claim-made-in-run-level': ([(T, "    (let ((begun #f) (ended #f) (level #f) (raising #f) (rollback-failure #f))",
                      "    (let* ((claim! (let ((t #f)) (lambda () (and (not t) (begin (set! t #t) #t)))))\n           (begun #f) (ended #f) (level #f) (raising #f) (rollback-failure #f))")], TX),
 'M03-claim-taken-outside-the-section': ([(T, "        (let ((outcome\n               (critical-section\n                (if (not (claim!))",
                      "        (let* ((mine (claim!))\n               (outcome\n               (critical-section\n                (if (not mine)")], TX),
 # --- the plan in the BEGIN's section
 'M04-plan-in-its-own-section': ([(T, begun_head,
"""        (let* ((plan* (if (not (claim!))
                          '(claimed)
                          (guard (c (#t (list 'raised c)))
                                  (call-with-open-handle who db
                                    (lambda (handle)
                                      (let ((held (held-state db)))
                                        (if held
                                            (cons 'not-finished held)
                                            (begin-plan (sqlite3-get-autocommit handle) (database-depth db)
                                                        mode))))))))
               (outcome
               (critical-section
                (if (eq? (car plan*) 'claimed)
                    '(claimed)
                    (let ((plan plan*))
                      (if (eq? (car plan) 'begin)""")], TX),
 'M05-refusal-pass-in-its-own-section': ([(T, begun_head,
"""        (let* ((held* (guard (c (#t #f)) (call-with-open-handle who db (lambda (h) (held-state db)))))
               (outcome
               (critical-section
                (if (not (claim!))
                    '(claimed)
                    (let ((plan (guard (c (#t (list 'raised c)))
                                  (call-with-open-handle who db
                                    (lambda (handle)
                                      (let ((held held*))
                                        (if held
                                            (cons 'not-finished held)
                                            (begin-plan (sqlite3-get-autocommit handle) (database-depth db)
                                                        mode))))))))
                      (if (eq? (car plan) 'begin)""")], TX),
 # --- the shut, in with-transaction
 'M06-rollback-not-shut': ([(T, "        (call-with-latch-shut db\n          (lambda ()\n            (let loop ((rest statements))",
                      "        ((lambda (db thunk) (thunk)) db\n          (lambda ()\n            (let loop ((rest statements))")], TX),
 'M07-commit-shut-too': ([(T, "              (let ((outcome (issued who db (cadr plan) ended?\n                                     (lambda (o) (when (eq? o 'stepped) (end-level!))))))",
                      "              (let ((outcome (call-with-latch-shut db (lambda () (issued who db (cadr plan) ended?\n                                     (lambda (o) (when (eq? o 'stepped) (end-level!))))))))")], TX),
 'M08-failed-commit-rollback-not-shut': ([
     (T, "        (call-with-latch-shut db\n          (lambda ()\n            (let loop ((rest statements))",
         "        ((lambda (db thunk) (thunk)) db\n          (lambda ()\n            (let loop ((rest statements))"),
     (T, "(let ((failure (rolled-back! (cdr plan))))",
         "(let ((failure (call-with-latch-shut db (lambda () (rolled-back! (cdr plan))))))")], TX),
 'M09-shut-wrapper-does-nothing': ([(C, "        (interrupt-latch-shut! (unchecked-database-latch db) work)", "        (work)")], TX),
 # --- raised inside a section
 'M10-B8-commit-failure-in-a-section': ([(T, "(else (failed-commit!) (raise (cadr outcome)))",
                      "(else (critical-section (failed-commit!) (raise (cadr outcome))))")], TX),
 'M11-begin-failure-in-a-section': ([(T, "                ((eq? (car outcome) 'refused) (raise-transaction-refusal who outcome))\n                (else (raise (cadr outcome))))))",
                      "                ((eq? (car outcome) 'refused) (raise-transaction-refusal who outcome))\n                (else (critical-section (raise (cadr outcome)))))))")], TX),
 'M12-refusal-in-a-section': ([(T, "                 (assertion-violation who \"a statement of the connection is at a row or failed; reset or finalize it first\"\n                                      'statement-not-finished (cadr outcome) (caddr outcome)))",
                      "                 (critical-section (assertion-violation who \"a statement of the connection is at a row or failed; reset or finalize it first\"\n                                      'statement-not-finished (cadr outcome) (caddr outcome))))")], TX),
 'M13-ended-at-return-in-a-section': ([(T, "                      (else (failed-commit!) (raise (cadr outcome)))))\n              (raise-transaction-ended who))))",
                      "                      (else (failed-commit!) (raise (cadr outcome)))))\n              (critical-section (raise-transaction-ended who)))))")], TX),
 'M14-rollback-failure-in-a-section': ([(T, "              (raise (car failure)))))))))",
                      "              (critical-section (raise (car failure))))))))))")], TX),
 'M15-claim-refusal-in-a-section': ([(T, "((eq? (car outcome) 'claimed) (raise-transaction-ended who))",
                      "((eq? (car outcome) 'claimed) (critical-section (raise-transaction-ended who)))")], TX),
 'M16-body-check-in-a-section': ([(T, "        (assertion-violation who \"the body is no procedure\" 'not-a-procedure (shown-value body)))",
                      "        (critical-section (assertion-violation who \"the body is no procedure\" 'not-a-procedure (shown-value body))))")], TX),
 'M17-mode-refusal-in-a-section': ([(T, "          (raise-transaction-refusal who checked)))",
                      "          (critical-section (raise-transaction-refusal who checked))))")], TX),
 # --- the latch's shut
 'M20-shut-does-not-put-back': ([(I, "              (set-interruptible! latch found)\n", "              (if #f #f)\n")], SHUT + TX[:1]),
 'M21-shut-sets-interruptible': ([(I, "              (set-interruptible! latch found)\n", "              (set-interruptible! latch #t)\n")], SHUT),
 'M22-shut-without-the-mutex': ([(I, """                           (with-mutex (latch-mutex latch)
                             (let ((was (latch-interruptible latch)))
                               (set-latch-interruptible! latch #f)
                               was))))""", """                           (begin
                             (let ((was (latch-interruptible latch)))
                               (set-latch-interruptible! latch #f)
                               was))))"""), (I, "              (set-interruptible! latch found)\n", "              (set-latch-interruptible! latch found)\n")], SHUT),
 'M23-shut-holds-the-mutex-across-the-work': ([(I, """           (critical-section
            (let* ((found (critical-section
                           (with-mutex (latch-mutex latch)
                             (let ((was (latch-interruptible latch)))
                               (set-latch-interruptible! latch #f)
                               was))))
                   (answer (guard (c (#t (list 'raised c)))
                             (list 'answered (work)))))
              (set-interruptible! latch found)
              answer))))""", """           (critical-section
            (with-mutex (latch-mutex latch)
             (let* ((found (let ((was (latch-interruptible latch)))
                               (set-latch-interruptible! latch #f)
                               was))
                   (answer (guard (c (#t (list 'raised c)))
                             (list 'answered (work)))))
              (set-latch-interruptible! latch found)
              answer)))))""")], SHUT),
 'M24-shut-in-two-sections': ([(I, """           (critical-section
            (let* ((found (critical-section""", """           (begin
            (let* ((found (critical-section""")], SHUT),
 'M25-shut-raises-inside-its-section': ([(I, """                   (answer (guard (c (#t (list 'raised c)))
                             (list 'answered (work)))))""", """                   (answer (list 'answered (work))))""")], SHUT),
 'M26-shut-does-not-put-back-after-a-raise': ([(I, "              (set-interruptible! latch found)\n              answer", "              (when (eq? (car answer) 'answered) (set-interruptible! latch found))\n              answer")], SHUT),
 'M18-owner-check-in-a-section': ([(T, "      (check-database-owner who db)\n      (run-level who db mode body claim!)))",
                      "      (critical-section (check-database-owner who db))\n      (run-level who db mode body claim!)))")], TX[:1]),
 'M19-body-raise-handed-on-in-a-section': ([(T, "                  (lambda () (raise-continuable c))",
                      "                  (lambda () (critical-section (raise-continuable c)))")], TX[:1]),
 'M27-shut-calls-the-work-twice': ([(I, "                             (list 'answered (work)))))", "                             (list 'answered (begin (work) (work))))))")], SHUT),
 'M28-the-verb-does-nothing': ([(C, "    (interrupt-latch-interrupt! (unchecked-database-latch db)\n                                (lambda () (interrupt (unchecked-database-handle db))))",
                      "    (if #f #f)")], ['tests/test-interrupt-database.sps']),
 'M29-after-thunk-ignores-begun': ([(T, "              (when (and begun (not ended))", "              (when (not ended)")], ['tests/test-transaction-engine.sps']),
 'M29c-a-failed-begin-rolled-back': ([(T, "              (when (and begun (not ended))", "              (when (not ended)"),
      (T, "                      (if (eq? (car plan) 'begin)\n                          (issued who db (caddr plan) ended?",
          "                      (if (eq? (car plan) 'begin)\n                          (begin (set! level (cadr plan)) (issued who db (caddr plan) ended?"),
      (T, "                                      (set-database-depth! db (+ (database-depth db) 1)))))\n                          plan))))))",
          "                                      (set-database-depth! db (+ (database-depth db) 1))))))\n                          plan))))))"),
      ('src/chez-sqlite3/private/transaction-plan.sls', "    (cond ((or ended (not begun))", "    (cond (ended")],
     ['tests/test-transaction-engine.sps']),
 'M03b-claim-in-a-section-of-its-own': ([(T, "        (let ((outcome\n               (critical-section\n                (if (not (claim!))",
                      "        (let* ((mine (critical-section (claim!)))\n               (outcome\n               (critical-section\n                (if (not mine)")], TX),
 'W1-never-commits': ([(T, "          (if (eq? (car plan) 'commit)", "          (if #f")], ['tests/test-transaction-engine.sps']),
 'W2-suite-trials-at-capacity-0': ([('tests/test-transaction-engine.sps',
     "                   (set! db (open-database \":memory:\"))\n                   (execute! db \"create table t (x)\")\n                   (proc db))))",
     "                   (set! db (open-database \":memory:\" '((statement-cache . 0))))\n                   (execute! db \"create table t (x)\")\n                   (proc db))))")], ['tests/test-transaction-engine.sps']),
 'W3-suite-claim-trials-in-a-section': ([('tests/test-transaction-engine.sps',
     "                  (thunk (lambda ()\n                           (attempt (lambda ()\n                                      (set! entries (+ entries 1))",
     "                  (thunk (lambda ()\n                           (critical-section (attempt (lambda ()\n                                      (set! entries (+ entries 1))"),
     ('tests/test-transaction-engine.sps',
     "                                        (lambda () (execute! db \"insert into t values (?)\" fuel) 42))))))\n                  (run (lambda ()",
     "                                        (lambda () (execute! db \"insert into t values (?)\" fuel) 42)))))))\n                  (run (lambda ()"),
     ('tests/test-transaction-engine.sps',
     "        (only (chezscheme) make-engine foreign-procedure timer-interrupt-handler set-timer list-head",
     "        (only (chezscheme) make-engine foreign-procedure timer-interrupt-handler set-timer list-head critical-section")], ['tests/test-transaction-engine.sps']),
}

def plant(name):
    edits, suites = mutants[name]
    dest = os.path.join(root, 'build', 't', 'mut', name)
    subprocess.run(['rsync', '-a', '--delete', '--exclude', '.git', '--exclude', 'build', root + '/', dest + '/'], check=True)
    for f, old, new in edits:
        p = os.path.join(dest, f)
        s = open(p).read()
        n = s.count(old)
        if n != 1:
            sys.exit(f'{name}: {f}: the edit matches {n} times')
        s = s.replace(old, new)
        open(p, 'w').write(s)
    open(os.path.join(dest, 'SUITES'), 'w').write(' '.join(suites) + '\n')

names = sys.argv[1:] or sorted(mutants)
for n in names:
    plant(n)
    print(n)
